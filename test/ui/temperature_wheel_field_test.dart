import 'package:cycle_app/domain/decimal_display.dart';
import 'package:cycle_app/domain/temperature_steps.dart';
import 'package:cycle_app/l10n/app_localizations.dart';
import 'package:cycle_app/ui/temperature_wheel_field.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _wheel = ValueKey('diaryTemperatureWheel');
const _clearButton = ValueKey('diaryTemperatureClearButton');
const _bar = ValueKey('diaryTemperatureWheelBar');

String _label(double value, {String locale = 'en'}) =>
    formatDecimal(value, locale: locale, decimalDigits: 2);

Finder _wheelLabel(String label) =>
    find.descendant(of: find.byKey(_wheel), matching: find.text(label));

Finder _unitInWheel() =>
    find.descendant(of: find.byKey(_wheel), matching: find.text('°C'));

/// The selection bar's two horizontal rules, matched as colour-carrying containers.
Finder _barRules() => find.descendant(
  of: find.byKey(_bar),
  matching: find.byWidgetPredicate((w) => w is Container && w.color != null),
);

Set<Color> _barColors() =>
    _barRules().evaluate().map((e) => (e.widget as Container).color!).toSet();

class _Recorder {
  final List<double> committed = <double>[];
  int clears = 0;
}

Widget _host({
  double? value,
  double? suggestion,
  _Recorder? recorder,
  Locale locale = const Locale('en'),
}) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: locale,
  home: Scaffold(
    body: TemperatureWheelField(
      value: value,
      suggestion: suggestion,
      onChanged: recorder?.committed.add,
      onClear: recorder == null ? null : () => recorder.clears++,
    ),
  ),
);

/// The rendered [Text] of the label nearest the wheel's vertical centre —
/// the value the wheel is currently resting on. Candidates must parse as
/// bare numbers, so the selected item's unit Text (same dy as the number)
/// can never win the nearest-centre tie.
Text _centeredLabel(WidgetTester tester) {
  final wheelBox = tester.renderObject<RenderBox>(find.byKey(_wheel));
  final wheelCenter = wheelBox
      .localToGlobal(wheelBox.size.center(Offset.zero))
      .dy;
  final candidates = find
      .descendant(of: find.byKey(_wheel), matching: find.byType(Text))
      .evaluate()
      .where((element) {
        final data = (element.widget as Text).data;
        return data != null &&
            double.tryParse(data.replaceAll(',', '.')) != null;
      })
      .toList();
  Text best = candidates.first.widget as Text;
  var bestDistance = double.infinity;
  for (final element in candidates) {
    final box = element.renderObject! as RenderBox;
    final distance =
        (box.localToGlobal(box.size.center(Offset.zero)).dy - wheelCenter)
            .abs();
    if (distance < bestDistance) {
      bestDistance = distance;
      best = element.widget as Text;
    }
  }
  return best;
}

double _centeredValue(WidgetTester tester) =>
    double.parse(_centeredLabel(tester).data!.replaceAll(',', '.'));

/// The pixel distance of one wheel item, derived from the rendered labels
/// of the two grid steps adjacent to [centered] — a layout fact the tests
/// measure instead of hardcoding. The next higher step renders above, the
/// next lower below.
double _itemExtent(WidgetTester tester, double centered) {
  final index = TemperatureSteps.nearestIndex(centered);
  final above = tester.getCenter(
    _wheelLabel(_label(TemperatureSteps.valueAt(index + 1))),
  );
  final below = tester.getCenter(
    _wheelLabel(_label(TemperatureSteps.valueAt(index - 1))),
  );
  return (below.dy - above.dy) / 2;
}

/// One whole-step drag: dragging the wheel's content DOWN selects the next
/// HIGHER step (higher values sit on top of the wheel), dragging up selects
/// the next lower one. The drag carries the slop the way the form's shared
/// helper does: with the tap layer in the arena, DragStartBehavior.start
/// absorbs the first (slop-crossing) drag segment, so the segment past the
/// slop must span one whole item.
Future<void> _dragOneStep(
  WidgetTester tester, {
  required double centered,
  required bool higher,
}) async {
  final extent = _itemExtent(tester, centered);
  final drag = extent + kDragSlopDefault;
  await tester.drag(find.byKey(_wheel), Offset(0, higher ? drag : -drag));
  await tester.pumpAndSettle();
}

/// Repeated strong flings until [label] (a window-end grid value) is on
/// screen — the wheel clamps at its ends. [downward] flings the content
/// down, toward the higher values at the wheel's top.
Future<void> _flingToLabel(
  WidgetTester tester,
  String label, {
  required bool downward,
}) async {
  final target = _wheelLabel(label);
  for (var i = 0; i < 30 && target.evaluate().isEmpty; i++) {
    await tester.fling(
      find.byKey(_wheel),
      Offset(0, downward ? 600 : -600),
      8000,
    );
    await tester.pumpAndSettle();
  }
}

/// One mouse-wheel notch directly over the wheel's centre, without settling:
/// [dy] is the raw scroll delta (100 is a typical Linux/Windows notch,
/// negative = wheel-up). The caller pumps when it wants a settle.
Future<void> _notch(WidgetTester tester, double dy) async {
  final p = TestPointer(3, PointerDeviceKind.mouse)
    ..hover(tester.getCenter(find.byKey(_wheel)));
  await tester.sendEventToBinding(p.scroll(Offset(0, dy)));
}

/// Drags the wheel's content one item down and back to the starting item,
/// releasing only at the end — the settle lands on the starting item; the
/// slop accounting is the one [_dragOneStep] documents.
Future<void> _netZeroDrag(WidgetTester tester) async {
  final extent = _itemExtent(tester, _centeredValue(tester));
  final gesture = await tester.startGesture(
    tester.getCenter(find.byKey(_wheel)),
  );
  await gesture.moveBy(Offset(0, kDragSlopDefault));
  await tester.pump();
  await gesture.moveBy(Offset(0, extent));
  await tester.pump();
  await gesture.moveBy(Offset(0, -extent));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'renders the grid: 0.05 K apart, window ends reachable via the inverted direction',
    (tester) async {
      await tester.pumpWidget(_host(value: 36.70));

      expect(_wheelLabel('36.70'), findsOneWidget);
      expect(_wheelLabel('36.65'), findsOneWidget);
      expect(_wheelLabel('36.75'), findsOneWidget);

      // The wheel spans the settings window 34.0–42.0 °C; the top end holds
      // the higher values, so reaching it needs downward flings.
      await _flingToLabel(tester, '42.00', downward: true);
      expect(_wheelLabel('42.00'), findsOneWidget);
      await _flingToLabel(tester, '34.00', downward: false);
      expect(_wheelLabel('34.00'), findsOneWidget);
    },
  );

  testWidgets(
    'visual order: higher values above the centre, dragging content down selects higher',
    (tester) async {
      final recorder = _Recorder();
      await tester.pumpWidget(_host(value: 36.70, recorder: recorder));

      final center = tester.getCenter(_wheelLabel('36.70')).dy;
      expect(
        tester.getCenter(_wheelLabel('36.75')).dy,
        lessThan(center),
        reason: 'the next higher step renders above the centred value',
      );
      expect(tester.getCenter(_wheelLabel('36.65')).dy, greaterThan(center));

      await _dragOneStep(tester, centered: 36.70, higher: true);
      expect(recorder.committed, [36.75]);

      await _dragOneStep(tester, centered: 36.75, higher: false);
      expect(recorder.committed, [36.75, 36.70]);
    },
  );

  testWidgets(
    'compact geometry: 120–160 dp wide, horizontally centered, about three visible items',
    (tester) async {
      await tester.pumpWidget(_host(value: 36.70));

      final rect = tester.getRect(find.byKey(_wheel));
      expect(rect.width, inInclusiveRange(120, 160));
      final screenWidth =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      expect(rect.center.dx, closeTo(screenWidth / 2, 1));

      final extent = _itemExtent(tester, 36.70);
      expect(rect.height, inInclusiveRange(2.5 * extent, 3.5 * extent));
    },
  );

  testWidgets('prominence: centred taller than neighbours in both states', (
    tester,
  ) async {
    // Label heights are read off the render boxes, not global rects: the
    // wheel's cylindrical projection foreshortens off-centre items, which
    // would distort a centre-vs-neighbour comparison.
    double labelHeight(String label) =>
        tester.renderObject<RenderBox>(_wheelLabel(label)).size.height;

    await tester.pumpWidget(_host(value: 36.70));

    expect(
      labelHeight('36.70'),
      greaterThan(labelHeight('36.75')),
      reason:
          'in the solid state the centred value renders larger than the step above it',
    );
    expect(labelHeight('36.70'), greaterThan(labelHeight('36.65')));

    await tester.pumpWidget(_host(suggestion: 36.55));
    expect(
      labelHeight('36.55'),
      greaterThan(labelHeight('36.60')),
      reason:
          'the 20 pt centre vs 17 pt neighbour difference persists as a cue in the gray state too',
    );
    expect(labelHeight('36.55'), greaterThan(labelHeight('36.50')));
  });

  testWidgets(
    'the selected item carries a °C unit beside the number in every state',
    (tester) async {
      await tester.pumpWidget(_host(value: 36.70));
      expect(_unitInWheel(), findsOneWidget);
      final number = tester.getRect(_wheelLabel('36.70'));
      final unit = tester.getRect(_unitInWheel());
      expect(
        unit.height,
        lessThan(number.height),
        reason: 'the unit renders smaller than the value',
      );
      expect(
        unit.center.dx,
        greaterThan(number.center.dx),
        reason: 'the unit sits right of the number',
      );

      await tester.pumpWidget(_host(suggestion: 36.55));
      expect(_unitInWheel(), findsOneWidget);
      await tester.pumpWidget(_host());
      expect(_unitInWheel(), findsOneWidget);
    },
  );

  testWidgets(
    'the °C unit follows the live selection; neighbours stay plain numbers',
    (tester) async {
      final recorder = _Recorder();
      await tester.pumpWidget(_host(value: 36.70, recorder: recorder));

      await _dragOneStep(tester, centered: 36.70, higher: false);
      expect(recorder.committed, [36.65]);

      expect(
        _unitInWheel(),
        findsOneWidget,
        reason: 'exactly the selected item carries the unit',
      );
      expect(
        (tester.getCenter(_unitInWheel()).dy -
                tester.getCenter(_wheelLabel('36.65')).dy)
            .abs(),
        lessThanOrEqualTo(1),
        reason:
            'the unit rides exactly the newly centred number (neighbour-plainness is asserted by the findsOneWidget above)',
      );
    },
  );

  testWidgets(
    'the widest selected label "42,00 °C" fits the 140 dp wheel overflow-free',
    (tester) async {
      await tester.pumpWidget(_host(value: 42.00, locale: const Locale('de')));

      expect(tester.takeException(), isNull);
      final wheelRect = tester.getRect(find.byKey(_wheel));
      bool inside(Rect outer, Rect inner) =>
          outer.contains(inner.topLeft) && outer.contains(inner.bottomRight);
      expect(
        inside(wheelRect, tester.getRect(_wheelLabel('42,00'))),
        isTrue,
        reason: 'the centred number stays inside the wheel',
      );
      expect(
        inside(wheelRect, tester.getRect(_unitInWheel())),
        isTrue,
        reason: 'the unit stays inside the wheel',
      );
    },
  );

  testWidgets(
    'the centred number sits on the neighbours’ centre line in both states',
    (tester) async {
      double centreDx(String label) => tester.getCenter(_wheelLabel(label)).dx;

      await tester.pumpWidget(_host(value: 36.70));
      final solid = centreDx('36.70');
      expect(
        solid,
        closeTo(centreDx('36.75'), 1),
        reason:
            'the °C unit beside the number must not shift the number off the neighbours’ centre line',
      );
      expect(solid, closeTo(centreDx('36.65'), 1));

      await tester.pumpWidget(_host(suggestion: 36.55));
      final gray = centreDx('36.55');
      expect(gray, closeTo(centreDx('36.60'), 1));
      expect(gray, closeTo(centreDx('36.50'), 1));
    },
  );

  testWidgets(
    'a 2.0 text scale keeps the widest selected label overflow-free and centred',
    (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(_host(value: 42.00, locale: const Locale('de')));

      expect(tester.takeException(), isNull);
      expect(
        tester.getCenter(_wheelLabel('42,00')).dx,
        closeTo(tester.getCenter(_wheelLabel('41,95')).dx, 1),
        reason:
            'the fitted-down selected row still puts the number on the neighbours’ centre line',
      );
    },
  );

  testWidgets('the clear × is vertically centered on the wheel band', (
    tester,
  ) async {
    await tester.pumpWidget(_host(value: 36.70));

    final clear = tester.getCenter(find.byKey(_clearButton));
    final wheel = tester.getCenter(find.byKey(_wheel));
    expect(
      (clear.dy - wheel.dy).abs(),
      lessThanOrEqualTo(1),
      reason: 'the × aligns with the central (selected) temperature',
    );
  });

  testWidgets(
    'the selection bar is always visible and hugs the centred band in both states',
    (tester) async {
      for (final (host, centered) in [
        (_host(suggestion: 36.55), 36.55),
        (_host(), 36.25),
        (_host(value: 36.70), 36.70),
      ]) {
        await tester.pumpWidget(host);
        expect(
          _barRules(),
          findsNWidgets(2),
          reason: 'the bar renders in every state',
        );
        final wheelRect = tester.getRect(find.byKey(_wheel));
        final extent = _itemExtent(tester, centered);
        final ruleCenters =
            _barRules()
                .evaluate()
                .map((e) => tester.getRect(find.byWidget(e.widget)).center.dy)
                .toList()
              ..sort();
        expect(
          ruleCenters[0],
          closeTo(wheelRect.top + extent, 2),
          reason: 'the upper rule sits just above the centred band',
        );
        expect(
          ruleCenters[1],
          closeTo(wheelRect.bottom - extent, 2),
          reason: 'the lower rule sits just below the centred band',
        );
      }
    },
  );

  testWidgets(
    'bar colour: outline while uncommitted, primary once a value is committed',
    (tester) async {
      Color barColor() {
        final colors = _barColors();
        expect(
          colors,
          hasLength(1),
          reason: 'both rules share the state colour',
        );
        return colors.single;
      }

      await tester.pumpWidget(_host(suggestion: 36.55));
      expect(
        barColor(),
        Theme.of(tester.element(find.byKey(_wheel))).colorScheme.outline,
        reason: 'a suggestion is not committed: the bar stays neutral',
      );

      await tester.pumpWidget(_host());
      expect(
        barColor(),
        Theme.of(tester.element(find.byKey(_wheel))).colorScheme.outline,
        reason: 'nothing is stored: the bar stays neutral',
      );

      await tester.pumpWidget(_host(value: 36.70));
      expect(
        barColor(),
        Theme.of(tester.element(find.byKey(_wheel))).colorScheme.primary,
        reason: 'a committed value turns the bar to the accent colour',
      );
    },
  );

  testWidgets('gray state: suggestion shown, no clear button', (tester) async {
    await tester.pumpWidget(_host(suggestion: 36.55));

    final label = _centeredLabel(tester);
    expect(label.data, '36.55');
    expect(find.byKey(_clearButton), findsNothing);
  });

  testWidgets(
    'label colours: gray all onSurface; committed centre and unit primary, neighbours onSurface',
    (tester) async {
      Color? colorOf(String label) =>
          tester.widget<Text>(_wheelLabel(label)).style?.color;
      Color? unitColor() => tester.widget<Text>(_unitInWheel()).style?.color;

      await tester.pumpWidget(_host(suggestion: 36.55));
      var scheme = Theme.of(tester.element(find.byKey(_wheel))).colorScheme;
      for (final label in ['36.50', '36.55', '36.60']) {
        expect(
          colorOf(label),
          scheme.onSurface,
          reason:
              'the uncommitted numbers are not lightened — the bar carries the state signal',
        );
      }
      expect(
        unitColor(),
        scheme.onSurface,
        reason: "the unit follows the centre's state colour",
      );

      await tester.pumpWidget(_host(value: 36.70));
      scheme = Theme.of(tester.element(find.byKey(_wheel))).colorScheme;
      expect(
        colorOf('36.70'),
        scheme.primary,
        reason:
            'a committed value renders the centre in the selected-entry colour',
      );
      expect(
        unitColor(),
        scheme.primary,
        reason: "the unit follows the centre's state colour",
      );
      for (final label in ['36.65', '36.75']) {
        expect(colorOf(label), scheme.onSurface);
      }
    },
  );

  testWidgets(
    'sizes in the gray state: centre 20 pt regular, neighbours 17 pt regular',
    (tester) async {
      await tester.pumpWidget(_host(suggestion: 36.55));

      TextStyle styleOf(String label) =>
          tester.widget<Text>(_wheelLabel(label)).style!;
      final centre = styleOf('36.55');
      expect(centre.fontSize, 20, reason: 'the centre is always 20 pt');
      expect(
        centre.fontWeight ?? FontWeight.w400,
        FontWeight.w400,
        reason: 'only a commit turns the centre bold',
      );
      for (final label in ['36.50', '36.60']) {
        final style = styleOf(label);
        expect(style.fontSize, 17);
        expect(
          style.fontWeight ?? FontWeight.w400,
          FontWeight.w400,
          reason: 'the gray state renders regular weight',
        );
      }
    },
  );

  testWidgets(
    'always renders: gray default centred in the 36.00–36.50 window, no clear button',
    (tester) async {
      await tester.pumpWidget(_host());

      final label = _centeredLabel(tester);
      final centered = double.parse(label.data!.replaceAll(',', '.'));
      expect(centered, inInclusiveRange(36.00, 36.50));
      expect(find.byKey(_clearButton), findsNothing);
    },
  );

  testWidgets(
    'solid state: centred 20 pt bold primary, neighbours 17 pt, clear button with tooltip and onClear',
    (tester) async {
      final recorder = _Recorder();
      await tester.pumpWidget(_host(value: 36.70, recorder: recorder));

      final label = _centeredLabel(tester);
      expect(label.data, '36.70');
      final scheme = Theme.of(tester.element(find.byKey(_wheel))).colorScheme;
      expect(
        label.style?.fontSize,
        20,
        reason: 'a committed value renders the centred number at 20 pt',
      );
      expect(
        label.style?.fontWeight,
        FontWeight.bold,
        reason: 'a committed value renders the centred number bold',
      );
      expect(
        label.style?.color,
        scheme.primary,
        reason:
            'a committed value renders the centred number in the selected-entry colour',
      );
      expect(
        tester.widget<Text>(_wheelLabel('36.65')).style?.fontSize,
        17,
        reason:
            'the neighbours never change size across states — no committed jump',
      );
      expect(tester.widget<Text>(_wheelLabel('36.75')).style?.fontSize, 17);
      expect(
        tester.widget<Text>(_unitInWheel()).style?.color,
        scheme.primary,
        reason: "the unit follows the centre's state colour",
      );
      expect(find.byKey(_clearButton), findsOneWidget);
      expect(find.byTooltip('Remove temperature'), findsOneWidget);

      await tester.tap(find.byKey(_clearButton));
      await tester.pump();
      expect(recorder.clears, 1);
      expect(
        recorder.committed,
        isEmpty,
        reason:
            'the × sits above the tap layer, so its recognizer wins the '
            'gesture arena — a tap on the × clears and never commits',
      );
    },
  );

  testWidgets('an off-grid stored value displays the nearest step', (
    tester,
  ) async {
    await tester.pumpWidget(_host(value: 36.68));

    expect(_wheelLabel('36.70'), findsOneWidget);
    expect(_wheelLabel('36.68'), findsNothing);
    expect(_centeredLabel(tester).data, '36.70');
  });

  testWidgets(
    'scrolling commits: a suggestion turns into a value only through a user scroll',
    (tester) async {
      final recorder = _Recorder();
      await tester.pumpWidget(_host(suggestion: 36.55, recorder: recorder));
      expect(
        recorder.committed,
        isEmpty,
        reason: 'the suggestion itself is never committed',
      );

      await _dragOneStep(tester, centered: 36.55, higher: true);
      expect(recorder.committed, [36.60]);
    },
  );

  testWidgets(
    'a net-zero drag (down and back to the starting item, released only at the end) commits the starting value',
    (tester) async {
      final recorder = _Recorder();
      await tester.pumpWidget(_host(value: 36.70, recorder: recorder));

      await _netZeroDrag(tester);

      expect(
        recorder.committed,
        [36.70],
        reason:
            'every user scroll settle commits — re-entering the same value '
            'needs no scroll-away detour',
      );
    },
  );

  testWidgets(
    'a net-zero drag from the gray suggestion commits it and turns the wheel solid',
    (tester) async {
      final recorder = _Recorder();
      await tester.pumpWidget(
        _CommittingHost(suggestion: 36.55, recorder: recorder),
      );

      await _netZeroDrag(tester);

      expect(recorder.committed, [36.55]);
      final scheme = Theme.of(tester.element(find.byKey(_wheel))).colorScheme;
      expect(_barColors(), {
        scheme.primary,
      }, reason: 'the commit turns the bar to the accent colour');
      expect(
        _centeredLabel(tester).style?.fontWeight,
        FontWeight.bold,
        reason: 'the commit renders the centred number bold',
      );
    },
  );

  testWidgets(
    'a tap commits the centred suggestion and turns the wheel solid',
    (tester) async {
      final recorder = _Recorder();
      await tester.pumpWidget(
        _CommittingHost(suggestion: 36.55, recorder: recorder),
      );

      await tester.tap(find.byKey(_wheel));
      await tester.pumpAndSettle();

      expect(recorder.committed, [36.55]);
      final scheme = Theme.of(tester.element(find.byKey(_wheel))).colorScheme;
      expect(_barColors(), {scheme.primary});
      expect(_centeredLabel(tester).style?.fontWeight, FontWeight.bold);
      expect(find.byKey(_clearButton), findsOneWidget);
    },
  );

  testWidgets('a tap on the unset default commits the default centre (36.25)', (
    tester,
  ) async {
    final recorder = _Recorder();
    await tester.pumpWidget(_host(recorder: recorder));

    await tester.tap(find.byKey(_wheel));
    await tester.pumpAndSettle();

    expect(recorder.committed, [36.25]);
  });

  testWidgets(
    'a tap in the solid state re-fires onChanged with the same value',
    (tester) async {
      final recorder = _Recorder();
      await tester.pumpWidget(_host(value: 36.70, recorder: recorder));

      await tester.tap(find.byKey(_wheel));
      await tester.pumpAndSettle();

      expect(recorder.committed, [36.70]);
    },
  );

  testWidgets(
    'a parent-provided value change realigns the wheel without committing',
    (tester) async {
      final recorder = _Recorder();
      await tester.pumpWidget(_host(value: 36.70, recorder: recorder));
      expect(recorder.committed, isEmpty);

      await tester.pumpWidget(_host(value: 36.55, recorder: recorder));

      expect(
        _centeredLabel(tester).data,
        '36.55',
        reason: 'the wheel realigns to the new value',
      );
      expect(
        recorder.committed,
        isEmpty,
        reason: 'the parent-driven realignment must not fire onChanged',
      );
    },
  );

  testWidgets(
    'an unrelated parent rebuild leaves a wheel resting off-target alone',
    (tester) async {
      final recorder = _Recorder();
      await tester.pumpWidget(_host(value: 36.70, recorder: recorder));

      // The scroll commits 36.75; the static host does not apply it, so the
      // wheel now rests off the widget's target value.
      await _dragOneStep(tester, centered: 36.70, higher: true);
      expect(recorder.committed, [36.75]);

      // An unrelated parent rebuild with unchanged props: the target did not
      // change, so the wheel must keep the user's position.
      await tester.pumpWidget(_host(value: 36.70, recorder: recorder));

      expect(recorder.committed, [
        36.75,
      ], reason: 'the rebuild must not re-commit or fire onChanged');
      expect(
        _centeredLabel(tester).data,
        '36.75',
        reason: 'the rebuild must not snap the wheel back to the stored value',
      );
    },
  );

  testWidgets('wheel labels follow the locale decimal separator', (
    tester,
  ) async {
    await tester.pumpWidget(_host(value: 36.70, locale: const Locale('de')));

    expect(_wheelLabel('36,70'), findsOneWidget);
    expect(_wheelLabel('36.70'), findsNothing);
  });

  testWidgets('one mouse notch over the wheel steps exactly one grid item: '
      'wheel-down lower, wheel-up higher', (tester) async {
    final recorder = _Recorder();
    await tester.pumpWidget(_host(value: 36.70, recorder: recorder));

    await _notch(tester, 100);
    await tester.pumpAndSettle();
    expect(recorder.committed, [36.65]);
    expect(_centeredLabel(tester).data, '36.65');

    await _notch(tester, -100);
    await tester.pumpAndSettle();
    expect(recorder.committed, [36.65, 36.70]);
    expect(_centeredLabel(tester).data, '36.70');
  });

  testWidgets(
    'a burst of 3 back-to-back notches moves exactly 3 grid items, no overshoot',
    (tester) async {
      final recorder = _Recorder();
      await tester.pumpWidget(_host(value: 36.70, recorder: recorder));

      await _notch(tester, 100);
      await _notch(tester, 100);
      await _notch(tester, 100);
      await tester.pumpAndSettle();

      expect(_centeredLabel(tester).data, '36.55');
      expect(
        recorder.committed.last,
        36.55,
        reason: 'the coalesced burst settles exactly 3 items away',
      );
    },
  );

  testWidgets(
    'one oversized notch (dy = 500) still steps exactly one grid item',
    (tester) async {
      final recorder = _Recorder();
      await tester.pumpWidget(_host(value: 36.70, recorder: recorder));

      await _notch(tester, 500);
      await tester.pumpAndSettle();
      expect(recorder.committed, [36.65]);
      expect(_centeredLabel(tester).data, '36.65');
    },
  );

  testWidgets(
    'two sub-notch events (dy = 18 each) accumulate residue into exactly one step',
    (tester) async {
      final recorder = _Recorder();
      await tester.pumpWidget(_host(value: 36.70, recorder: recorder));

      await _notch(tester, 18);
      await _notch(tester, 18);
      await tester.pumpAndSettle();
      expect(recorder.committed, [36.65]);
      expect(_centeredLabel(tester).data, '36.65');
    },
  );

  testWidgets(
    'a mouse notch from the gray suggestion commits via onChanged and turns the wheel solid',
    (tester) async {
      final recorder = _Recorder();
      await tester.pumpWidget(
        _CommittingHost(suggestion: 36.55, recorder: recorder),
      );

      await _notch(tester, 100);
      await tester.pumpAndSettle();

      expect(recorder.committed, [
        36.50,
      ], reason: 'wheel-down from the suggestion selects the next lower step');
      final context = tester.element(find.byKey(_wheel));
      final scheme = Theme.of(context).colorScheme;
      expect(_barColors(), {
        scheme.primary,
      }, reason: 'the commit turns the bar to the accent colour');
      expect(
        _centeredLabel(tester).style?.fontSize,
        20,
        reason: 'the committed value renders the centred number 20 pt bold',
      );
      expect(_centeredLabel(tester).style?.fontWeight, FontWeight.bold);
      expect(
        _centeredLabel(tester).style?.color,
        scheme.primary,
        reason:
            'the commit also turns the centred number to the selected-entry colour',
      );
      expect(
        tester.widget<Text>(_unitInWheel()).style?.color,
        scheme.primary,
        reason: "the unit follows the centre's state colour",
      );
      expect(find.byKey(_clearButton), findsOneWidget);
    },
  );

  testWidgets('window-end notches are no-ops without commits', (tester) async {
    final recorder = _Recorder();
    await tester.pumpWidget(_host(value: 42.00, recorder: recorder));

    await _notch(tester, -100);
    await tester.pumpAndSettle();
    expect(recorder.committed, isEmpty);
    expect(_centeredLabel(tester).data, '42.00');

    await tester.pumpWidget(_host(value: 34.00, recorder: recorder));
    await _notch(tester, 100);
    await tester.pumpAndSettle();
    expect(recorder.committed, isEmpty);
    expect(_centeredLabel(tester).data, '34.00');
  });
}

/// A host that applies [onChanged] back into [value] the way the diary form
/// does, so a commit turns the wheel into the solid state in place.
class _CommittingHost extends StatefulWidget {
  const _CommittingHost({this.suggestion, required this.recorder});

  final double? suggestion;
  final _Recorder recorder;

  @override
  State<_CommittingHost> createState() => _CommittingHostState();
}

class _CommittingHostState extends State<_CommittingHost> {
  double? _value;

  @override
  Widget build(BuildContext context) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: TemperatureWheelField(
        value: _value,
        suggestion: widget.suggestion,
        onChanged: (v) => setState(() {
          _value = v;
          widget.recorder.committed.add(v);
        }),
        onClear: () => widget.recorder.clears++,
      ),
    ),
  );
}
