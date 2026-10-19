import 'dart:async';

import 'package:cycle_app/domain/decimal_display.dart';
import 'package:cycle_app/domain/temperature_steps.dart';
import 'package:cycle_app/l10n/app_localizations.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

const double _itemExtent = 36;
const double _wheelHeight = 3 * _itemExtent;
const double _wheelWidth = 140;
const double _selectedFontSize = 20;
const double _neighbourFontSize = 17;
const double _unitFontSize = 13;

/// Symmetric side slots of the selected row: equal widths put the number's
/// centre exactly on the neighbours' centre line at every text scale.
const double _unitSlotWidth = 18;
const double _barThickness = 2;

/// The notch animation is a short ease-out so a burst of notches feels immediate.
const Duration _notchAnimationDuration = Duration(milliseconds: 120);

class TemperatureWheelField extends StatefulWidget {
  const TemperatureWheelField({
    super.key,
    required this.value,
    this.suggestion,
    this.onChanged,
    this.onClear,
  });

  /// The selected day's own temperature, if one is entered or stored. An
  /// off-grid stored value renders at its nearest 0.05 K step — the stored
  /// value itself is never rewritten.
  final double? value;

  /// The most recent earlier entry's temperature, proposed while [value] is
  /// absent. It is display only — a user scroll settle or tap (which fire
  /// [onChanged]) is what turns it into a value.
  final double? suggestion;

  /// The grid value a user scroll settle or a tap on the wheel commits.
  final ValueChanged<double>? onChanged;

  /// The clear button's tap, fired only while [value] is present.
  final VoidCallback? onClear;

  @override
  State<TemperatureWheelField> createState() => _TemperatureWheelFieldState();
}

class _TemperatureWheelFieldState extends State<TemperatureWheelField> {
  /// Default centre while nothing is stored and no suggestion exists, inside
  /// the owner-chosen 36.00–36.50 window.
  static final int _unsetItem = _displayIndexOf(36.25);

  /// The children sit in descending value order (42.00 first, the wheel top),
  /// so a display index maps to the grid index mirrored around the middle:
  /// display 0 ↔ grid 160, display 160 ↔ grid 0.
  static int _displayIndexOf(double value) =>
      TemperatureSteps.count - 1 - TemperatureSteps.nearestIndex(value);

  static double _valueAtDisplay(int displayIndex) =>
      TemperatureSteps.valueAt(TemperatureSteps.count - 1 - displayIndex);

  late final FixedExtentScrollController _controller;
  bool _adjustingToState = false;

  /// The grid item the overlay's notch animation is heading to, or null when
  /// no notch is in flight; while pending, further notches coalesce onto it
  /// instead of restarting from a mid-flight position.
  int? _wheelTargetItem;

  /// Sub-notch wheel delta (dp) accumulated until it totals one item extent,
  /// so trackpad-style small scroll events still step in whole grid items.
  double _wheelResidue = 0;

  int get _targetItem => _targetItemOf(widget);

  static int _targetItemOf(TemperatureWheelField widget) {
    final shown = widget.value ?? widget.suggestion;
    return shown == null ? _unsetItem : _displayIndexOf(shown);
  }

  @override
  void initState() {
    super.initState();
    _controller = FixedExtentScrollController(initialItem: _targetItem);
  }

  @override
  void didUpdateWidget(TemperatureWheelField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final target = _targetItem;
    // Realign only when the parent's target actually changed: an unrelated
    // rebuild while the wheel rests off-target (the parent has not applied a
    // committed value yet, or a fling is still settling) must not snap the
    // wheel back and kill the user's position.
    if (target == _targetItemOf(oldWidget) ||
        target == _controller.selectedItem) {
      return;
    }
    // The parent changed the state (clear, suggestion swap, off-grid day
    // navigation): realign the wheel without firing [onChanged].
    _wheelTargetItem = null;
    _wheelResidue = 0;
    _adjustingToState = true;
    _controller.jumpToItem(target);
    _adjustingToState = false;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification notification) {
    if (_adjustingToState || notification is! ScrollEndNotification) {
      return false;
    }
    // The wheel settled — by the notch animation or a user drag — so any
    // pending notch target has been reached or superseded.
    _wheelTargetItem = null;
    // Every user settle commits — even a net-zero drag back to the starting
    // item, so re-entering the same value needs no scroll-away detour.
    widget.onChanged?.call(_valueAtDisplay(_controller.selectedItem));
    return false;
  }

  // Hit-testing reaches this topmost overlay before the inner Scrollable,
  // and the PointerSignalResolver keeps only the first registration — so
  // the Scrollable's raw pixel-delta handling never runs.
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || event.scrollDelta.dy == 0) {
      return;
    }
    // Sub-notch and end-of-window deltas must be consumed here too — falling
    // through to the inner Scrollable would settle them onto whole items.
    GestureBinding.instance.pointerSignalResolver.register(
      event,
      _handlePointerScroll,
    );
  }

  void _handlePointerScroll(PointerSignalEvent event) {
    final scrollEvent = event as PointerScrollEvent;
    final double dy = scrollEvent.scrollDelta.dy;
    if (dy == 0.0) {
      return;
    }
    int steps;
    if (dy.abs() >= _itemExtent) {
      // Oversized deltas (accelerated wheels, OS-coalesced notches) step
      // one item, so fast scrolling never skips intermediate grid values.
      steps = 1;
    } else {
      _wheelResidue += dy.abs();
      steps = _wheelResidue ~/ _itemExtent;
      _wheelResidue -= steps * _itemExtent;
    }
    if (steps > 0) {
      // Wheel-down (positive delta) selects the next lower value, mirroring
      // the wheel's inverted drag direction.
      final int direction = dy > 0.0 ? 1 : -1;
      final int from = _wheelTargetItem ?? _controller.selectedItem;
      final int target = (from + direction * steps).clamp(
        0,
        TemperatureSteps.count - 1,
      );
      if (target != from) {
        // Coalesce: re-aiming an absolute animateToItem target mid-burst
        // makes N notches settle exactly N items away with one commit.
        _wheelTargetItem = target;
        unawaited(
          _controller.animateToItem(
            target,
            duration: _notchAnimationDuration,
            curve: Curves.easeOut,
          ),
        );
      }
    }
    scrollEvent.respond(allowPlatformDefault: false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    final theme = Theme.of(context);
    final solid = widget.value != null;
    final labelColor = theme.colorScheme.onSurface;
    final centerColor = solid ? theme.colorScheme.primary : labelColor;
    final barColor = solid
        ? theme.colorScheme.primary
        : theme.colorScheme.outline;

    // Stack overlays (state bar, solid-state clear button, pointer-signal
    // listener) so the wheel stays horizontally centered with or without
    // them.
    return Center(
      child: SizedBox(
        width: _wheelWidth,
        height: _wheelHeight,
        child: Stack(
          children: [
            NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: ListWheelScrollView(
                key: const ValueKey('diaryTemperatureWheel'),
                controller: _controller,
                itemExtent: _itemExtent,
                diameterRatio: 1.5,
                physics: const FixedExtentScrollPhysics(),
                children: [
                  for (
                    var display = 0;
                    display < TemperatureSteps.count;
                    display++
                  )
                    _item(
                      display,
                      locale,
                      solid: solid,
                      labelColor: labelColor,
                      centerColor: centerColor,
                    ),
                ],
              ),
            ),
            Positioned(
              top: _itemExtent - _barThickness,
              bottom: _itemExtent - _barThickness,
              left: 0,
              right: 0,
              child: IgnorePointer(
                key: const ValueKey('diaryTemperatureWheelBar'),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [_barRule(barColor), _barRule(barColor)],
                ),
              ),
            ),
            // Translucent so drags still reach the wheel below; below the
            // clear × so the ×'s recognizer joins the arena first and wins
            // the tap (clear, never commit).
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => widget.onChanged?.call(
                  _valueAtDisplay(_controller.selectedItem),
                ),
              ),
            ),
            if (solid)
              Positioned(
                top: 0,
                bottom: 0,
                right: 0,
                child: Center(
                  child: IconButton(
                    key: const ValueKey('diaryTemperatureClearButton'),
                    icon: const Icon(Icons.close),
                    tooltip: l10n.diaryTemperatureClear,
                    onPressed: widget.onClear,
                  ),
                ),
              ),
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerSignal: _onPointerSignal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // The label style follows the wheel's live selection, so the centred item
  // keeps the larger font as the fling settles. The unit is a separate Text
  // so the number's data stays the bare locale number that tests locate by
  // string; its fixed-width slot keeps the number on the neighbours' centre
  // line instead of shifted left by the unit's width.
  Widget _item(
    int displayIndex,
    String locale, {
    required bool solid,
    required Color labelColor,
    required Color centerColor,
  }) {
    final step = _valueAtDisplay(displayIndex);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final selected = _controller.selectedItem == displayIndex;
        final numberStyle = TextStyle(
          fontSize: selected ? _selectedFontSize : _neighbourFontSize,
          fontWeight: solid && selected ? FontWeight.bold : null,
          color: selected ? centerColor : labelColor,
        );
        return Center(
          child: selected
              ? FittedBox(
                  // A large text scale doubles both fonts past the fixed
                  // wheel width, so scale the row down as a unit instead
                  // of overflowing.
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(width: _unitSlotWidth),
                      Text(_label(step, locale), style: numberStyle),
                      SizedBox(
                        width: _unitSlotWidth,
                        child: FittedBox(
                          // Shrink the unit into its fixed slot at large
                          // text scales instead of spilling past it.
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '°C',
                            style: TextStyle(
                              fontSize: _unitFontSize,
                              color: centerColor,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : Text(_label(step, locale), style: numberStyle),
        );
      },
    );
  }

  Widget _barRule(Color color) =>
      Container(height: _barThickness, color: color);

  String _label(double value, String locale) =>
      formatDecimal(value, locale: locale, decimalDigits: 2);
}
