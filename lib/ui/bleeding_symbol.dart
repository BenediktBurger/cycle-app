// The shared bleeding symbol: a square box whose bleed fill is a
// bottom-anchored fraction of the box HEIGHT — level 0 (none) paints
// nothing (the surfaces keep their own none appearance: the chart's empty
// cell, the diary's faint outlineVariant dot), level 1 (spotting) renders
// a dotted — interrupted — fill within the bottom quarter band, and
// levels 2–5 fill (level − 1)/4 of it (1/4, 2/4, 3/4, 4/4). The box
// itself sizes to its parent's box: the cycle chart pumps it unmargined
// into a bleeding row cell (the table cell box serves as the fill
// boundary), the diary tiles wrap it in a fixed 18 px square, and the
// glossary sample in a small fixed square — all three surfaces use this
// one widget, so the rendering convention cannot drift apart.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/models.dart';

/// The shared bleeding symbol — the square box with the bottom-anchored
/// fill-fraction rendering of a recorded [Bleeding] level.
///
/// Sized by the parent box (`Align` fills the incoming constraints), so a
/// caller decides the box: a chart cell, a square [SizedBox], a legend
/// slot. `level == 0` renders an empty box ([SizedBox.shrink]).
final class BleedingSymbol extends StatelessWidget {
  const BleedingSymbol({
    super.key,
    required this.bleeding,
    this.color,
    this.borderColor,
  });

  /// The recorded bleeding level the symbol renders.
  final Bleeding bleeding;

  /// The bleed color; defaults to the theme's error color (the color both
  /// screens render bleeding with).
  final Color? color;

  /// The box outline color; null draws no border — the chart's cells take
  /// their boundary from the table's day separators, while the standalone
  /// surfaces (diary tiles, glossary sample) outline the box so the fill
  /// fraction reads as such.
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    if (bleeding.level == 0) return const SizedBox.shrink();
    final bleedColor = color ?? Theme.of(context).colorScheme.error;

    Widget symbol = LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0) {
          return const SizedBox.shrink();
        }

        final Widget band;
        if (bleeding.level == 1) {
          // Dotted spotting: small round dots spread over the full box
          // width inside the bottom quarter band. Dot size and count are
          // derived from the box so the band never looks like a solid
          // quarter fill on any surface.
          var diameter = math.min(height / 4, 3.0);
          var count = (width / (diameter * 2)).floor();
          if (count < 3) {
            count = 3;
            diameter = math.min(diameter, width / count);
          }
          if (count > 24) count = 24;
          band = Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (var i = 0; i < count; i++)
                BleedingFill(
                  color: bleedColor,
                  diameter: diameter,
                  round: true,
                ),
            ],
          );
        } else {
          band = BleedingFill(color: bleedColor);
        }

        return Align(
          alignment: Alignment.bottomCenter,
          child: FractionallySizedBox(
            widthFactor: 1,
            heightFactor: bleeding.level == 1
                ? 1 / 4
                : (bleeding.level - 1) / 4,
            child: band,
          ),
        );
      },
    );

    final outline = borderColor;
    if (outline != null) {
      symbol = DecoratedBox(
        decoration: BoxDecoration(border: Border.all(color: outline)),
        child: symbol,
      );
    }
    return symbol;
  }
}

/// One painted region of a symbol's bleed fill: the solid bottom bar of a
/// menstruation-level day, or one dot of a spotting day. A public widget
/// (rather than a bare [Container]) so the widget tests can locate and
/// measure the fill regions with `getRect` — they pin the bottom-anchored
/// fill-fraction geometry across all three surfaces.
final class BleedingFill extends StatelessWidget {
  const BleedingFill({
    super.key,
    required this.color,
    this.diameter,
    this.round = false,
  });

  /// The bleed color.
  final Color color;

  /// A dot's diameter; null (bar mode) paints whatever box the parent
  /// gives (the bottom-anchored fraction band).
  final double? diameter;

  /// Whether this region is a round dot (spotting) or the square bar.
  final bool round;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        color: color,
        shape: round ? BoxShape.circle : BoxShape.rectangle,
      ),
    );
  }
}
